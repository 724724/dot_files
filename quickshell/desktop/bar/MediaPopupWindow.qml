import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-media-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool shown:
        MediaService.popupOpen && MediaService.hasMedia
    readonly property color accentBase: MediaService.artAccent !== ""
        ? MediaService.artAccent : "#B8F23D"
    readonly property real accentLuminance:
        0.299 * accentBase.r + 0.587 * accentBase.g + 0.114 * accentBase.b
    readonly property color accent: accentLuminance < 0.48
        ? Qt.lighter(accentBase, 1.8) : accentBase
    readonly property bool pitchFeedbackVisible:
        MediaService.transpose !== 0 || MediaService.pitchState === "error"

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    Connections {
        target: MediaService
        function onPopupOpenChanged() {
            if (MediaService.popupOpen) {
                if (MediaService.popupScreen)
                    win.screen = MediaService.popupScreen
                win._surfaceVisible = true
                MediaService.refreshTimeline()
            }
        }
        function onPopupScreenChanged() {
            if (MediaService.popupOpen && MediaService.popupScreen)
                win.screen = MediaService.popupScreen
        }
        function onHasMediaChanged() {
            if (!MediaService.hasMedia)
                MediaService.popupOpen = false
        }
    }

    onVisibleChanged: if (visible) focusScope.forceActiveFocus()

    function timeText(seconds) {
        let total = Math.max(0, Math.floor(Number(seconds) || 0))
        let hours = Math.floor(total / 3600)
        let minutes = Math.floor((total % 3600) / 60)
        let secs = total % 60
        let mm = hours > 0 && minutes < 10 ? "0" + minutes : String(minutes)
        let ss = secs < 10 ? "0" + secs : String(secs)
        return hours > 0 ? hours + ":" + mm + ":" + ss : minutes + ":" + ss
    }

    component TransportButton: Rectangle {
        id: transport

        required property string glyph
        property real glyphSize: 30
        property real buttonWidth: 72
        signal triggered

        width: buttonWidth
        height: 48
        radius: 20
        color: transportHover.hovered
            ? Qt.rgba(1, 1, 1, 0.14)
            : "transparent"
        scale: transportTap.pressed ? 0.90 : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            text: transport.glyph
            color: "#ffffff"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: transport.glyphSize
            renderType: Text.NativeRendering
        }

        HoverHandler {
            id: transportHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: transportTap
            onTapped: transport.triggered()
        }
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: MediaService.popupOpen = false

        MouseArea {
            anchors.fill: parent
            onClicked: MediaService.popupOpen = false
        }

        Rectangle {
            id: card

            property bool scrubbing: false
            property real scrubRatio: 0
            readonly property real displayPosition: scrubbing
                ? scrubRatio * MediaService.duration : MediaService.position
            readonly property real progressRatio: MediaService.duration > 0
                ? Math.max(0, Math.min(1,
                    displayPosition / MediaService.duration)) : 0

            width: Math.min(450, win.width - 20)
            height: win.pitchFeedbackVisible ? 220 : 202
            x: Math.max(10, Math.min(
                MediaService.popupAnchorX - width / 2,
                win.width - width - 10))
            y: win.shown ? BarState.contentTop : BarState.contentTop - 8
            radius: 30
            color: "#151517"
            transformOrigin: Item.Top
            opacity: win.shown ? 1 : 0
            scale: win.shown ? 1 : 0.965
            visible: opacity > 0.002
            z: 10

            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }
            Behavior on y { AppleSpring { spring: 18 } }
            Behavior on height {
                AppleSpring { spring: 20; epsilon: 0.1 }
            }
            onOpacityChanged: {
                if (!win.shown && opacity <= 0.002)
                    win._surfaceVisible = false
            }

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 26
                samples: 53
                verticalOffset: 9
                color: Qt.rgba(0, 0, 0, 0.52)
            }

            ClippingRectangle {
                anchors.fill: parent
                radius: card.radius
                color: "#151517"

                Image {
                    id: backgroundArt
                    anchors.fill: parent
                    source: MediaService.artUrl
                    sourceSize.width: 512
                    sourceSize.height: 512
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    visible: false
                }

                MultiEffect {
                    anchors.fill: parent
                    source: backgroundArt
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 0.92
                    blurMax: 64
                    opacity: backgroundArt.status === Image.Ready ? 0.96 : 0
                    Behavior on opacity { AppleSpring { spring: 18 } }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    opacity: backgroundArt.status === Image.Ready ? 0.52 : 0.24
                    Behavior on opacity { AppleSpring { spring: 18 } }
                }
            }

            MouseArea { anchors.fill: parent }

            ClippingRectangle {
                id: cover
                x: 24
                y: 18
                width: 78
                height: 78
                radius: 17
                color: Qt.rgba(1, 1, 1, 0.10)

                Image {
                    anchors.fill: parent
                    source: MediaService.artUrl
                    sourceSize.width: 164
                    sourceSize.height: 164
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: MediaService.artUrl === ""
                    text: "󰎈"
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 30
                }
            }

            Column {
                anchors.left: cover.right
                anchors.leftMargin: 18
                anchors.right: popupEq.left
                anchors.rightMargin: 16
                anchors.verticalCenter: cover.verticalCenter
                spacing: 3

                Text {
                    width: parent.width
                    text: MediaService.title || "Not Playing"
                    color: "#ffffff"
                    elide: Text.ElideRight
                    font.family: "SF Pro Display"
                    font.pixelSize: 21
                    font.weight: Font.Bold
                    font.letterSpacing: -0.25
                }

                Text {
                    width: parent.width
                    text: MediaService.artist
                    color: Qt.rgba(1, 1, 1, 0.58)
                    elide: Text.ElideRight
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }
            }

            EqBars {
                id: popupEq
                anchors.right: parent.right
                anchors.rightMargin: 25
                anchors.verticalCenter: cover.verticalCenter
                levels: card.visible ? AudioEqService.levels : []
                active: card.visible && MediaService.isPlaying
                bars: 8
                barWidth: 3
                gap: 2
                maxHeight: 42
                barColor: win.accent
            }

            Item {
                id: timeline
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                y: 102
                height: 30

                Text {
                    id: elapsed
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 43
                    text: win.timeText(card.displayPosition)
                    color: Qt.rgba(1, 1, 1, 0.62)
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Text {
                    id: remaining
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 50
                    horizontalAlignment: Text.AlignRight
                    text: MediaService.duration > 0
                        ? "−" + win.timeText(Math.ceil(
                            Math.max(0, MediaService.duration
                                - card.displayPosition)))
                        : "−0:00"
                    color: Qt.rgba(1, 1, 1, 0.62)
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Item {
                    id: trackHit
                    anchors.left: elapsed.right
                    anchors.right: remaining.left
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28

                    Rectangle {
                        id: track
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: trackMouse.pressed ? 7 : 5
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.20)
                        Behavior on height { AppleSpring { spring: 20 } }

                        Rectangle {
                            width: parent.width * card.progressRatio
                            height: parent.height
                            radius: parent.radius
                            color: Qt.rgba(1, 1, 1, 0.78)
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(-width / 2, Math.min(
                                parent.width - width / 2,
                                parent.width * card.progressRatio - width / 2))
                            width: trackMouse.pressed || trackMouse.containsMouse
                                ? 12 : 0
                            height: width
                            radius: width / 2
                            color: "#ffffff"
                            Behavior on width { AppleSpring { spring: 20 } }
                        }
                    }

                    MouseArea {
                        id: trackMouse
                        anchors.fill: parent
                        enabled: MediaService.duration > 0
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: enabled
                            ? Qt.PointingHandCursor : Qt.ArrowCursor

                        function updateRatio(pointerX) {
                            card.scrubRatio = Math.max(0, Math.min(
                                1, pointerX / width))
                        }

                        onPressed: mouse => {
                            card.scrubbing = true
                            updateRatio(mouse.x)
                        }
                        onPositionChanged: mouse => {
                            if (pressed) updateRatio(mouse.x)
                        }
                        onReleased: mouse => {
                            updateRatio(mouse.x)
                            MediaService.seekTo(
                                card.scrubRatio * MediaService.duration)
                            card.scrubbing = false
                        }
                        onCanceled: card.scrubbing = false
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 139
                spacing: 10

                TransportButton {
                    glyph: "−1"
                    glyphSize: 16
                    buttonWidth: 52
                    onTriggered: MediaService.transposeBy(-1)
                }
                TransportButton {
                    glyph: "󰒮"
                    glyphSize: 31
                    buttonWidth: 62
                    onTriggered: MediaService.prev()
                }
                TransportButton {
                    glyph: MediaService.isPlaying ? "󰏤" : "󰐊"
                    glyphSize: 38
                    onTriggered: MediaService.playPause()
                }
                TransportButton {
                    glyph: "󰒭"
                    glyphSize: 31
                    buttonWidth: 62
                    onTriggered: MediaService.next()
                }
                TransportButton {
                    glyph: "+1"
                    glyphSize: 16
                    buttonWidth: 52
                    onTriggered: MediaService.transposeBy(1)
                }
            }

            Rectangle {
                id: restoreButton
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                width: restoreLabel.implicitWidth + 20
                height: 22
                radius: 11
                visible: opacity > 0.002
                opacity: win.pitchFeedbackVisible ? 1 : 0
                color: restoreHover.hovered
                    ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                scale: restoreTap.pressed ? 0.94 : 1

                Behavior on opacity { AppleSpring { spring: 18 } }
                Behavior on scale { AppleSpring { spring: 18 } }
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    id: restoreLabel
                    anchors.centerIn: parent
                    text: MediaService.pitchState === "error"
                        ? "Pitch unavailable  ·  Restore"
                        : "Pitch "
                            + (MediaService.transpose > 0 ? "+" : "")
                            + MediaService.transpose + " st  ·  Restore"
                    color: MediaService.pitchState === "error"
                        ? "#FF6961" : Qt.rgba(1, 1, 1, 0.62)
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                HoverHandler {
                    id: restoreHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: restoreTap
                    onTapped: MediaService.setTranspose(0)
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.16)
            }
        }
    }
}
