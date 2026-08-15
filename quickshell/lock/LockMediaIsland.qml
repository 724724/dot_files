import Quickshell.Widgets
import QtQuick

Rectangle {
    id: root

    required property var media
    required property var equalizer
    property bool shown: false
    property real preferredWidth: 450

    property bool scrubbing: false
    property real scrubRatio: 0
    readonly property real displayPosition: scrubbing
        ? scrubRatio * media.duration : media.position
    readonly property real progressRatio: media.duration > 0
        ? Math.max(0, Math.min(1, displayPosition / media.duration)) : 0
    readonly property color accentBase: media.artAccent !== ""
        ? media.artAccent : "#b8f23d"
    readonly property real accentLuminance:
        0.299 * accentBase.r + 0.587 * accentBase.g + 0.114 * accentBase.b
    readonly property color accent: accentLuminance < 0.48
        ? Qt.lighter(accentBase, 1.8) : accentBase

    width: preferredWidth
    height: 202
    radius: 30
    color: "#dc2b2b2f"
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.985
    visible: shown || opacity > 0.002
    transformOrigin: Item.Bottom
    transform: Translate {
        y: root.shown ? 0 : 8
        Behavior on y {
            LockSpring { spring: 14; damping: 1; epsilon: 0.001 }
        }
    }

    Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    Behavior on scale {
        LockSpring { spring: 14; damping: 1; epsilon: 0.001 }
    }

    function timeText(seconds) {
        const total = Math.max(0, Math.floor(Number(seconds) || 0))
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        const secs = total % 60
        const mm = hours > 0 && minutes < 10 ? "0" + minutes : String(minutes)
        const ss = secs < 10 ? "0" + secs : String(secs)
        return hours > 0 ? hours + ":" + mm + ":" + ss : minutes + ":" + ss
    }

    component TransportButton: Rectangle {
        id: button
        required property string glyph
        property real glyphSize: 30
        property real buttonWidth: 72
        signal triggered()

        width: buttonWidth
        height: 48
        radius: 20
        color: hover.hovered ? "#24ffffff" : "transparent"
        scale: tap.pressed ? 0.9 : 1

        Behavior on scale { LockSpring { spring: 20 } }
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: "#ffffff"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: button.glyphSize
            renderType: Text.NativeRendering
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: button.triggered() }
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "#d82b2b2f"

        Image {
            id: backgroundArt
            anchors.fill: parent
            source: root.media.artUrl
            sourceSize.width: 512
            sourceSize.height: 512
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            opacity: status === Image.Ready ? 0.16 : 0
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#26ffffff" }
                GradientStop { position: 0.32; color: "#08000000" }
                GradientStop { position: 1.0; color: "#2b000000" }
            }
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
        color: "#1affffff"

        Image {
            anchors.fill: parent
            source: root.media.artUrl
            sourceSize.width: 164
            sourceSize.height: 164
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }

        Text {
            anchors.centerIn: parent
            visible: root.media.artUrl === ""
            text: "󰎈"
            color: "#b8ffffff"
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
            text: root.media.title || "Not Playing"
            textFormat: Text.PlainText
            maximumLineCount: 1
            color: "#ffffff"
            elide: Text.ElideRight
            font.family: "SF Pro Display"
            font.pixelSize: 21
            font.weight: Font.Bold
            font.letterSpacing: -0.25
        }

        Text {
            width: parent.width
            text: root.media.artist
            textFormat: Text.PlainText
            maximumLineCount: 1
            color: "#94ffffff"
            elide: Text.ElideRight
            font.family: "SF Pro Display"
            font.pixelSize: 16
            font.weight: Font.Medium
        }
    }

    LockEqBars {
        id: popupEq
        anchors.right: parent.right
        anchors.rightMargin: 25
        anchors.verticalCenter: cover.verticalCenter
        levels: root.equalizer.levels
        active: root.media.isPlaying
        bars: 8
        barWidth: 3
        gap: 2
        maxHeight: 42
        barColor: root.accent
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
            text: root.timeText(root.displayPosition)
            color: "#9effffff"
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
            text: root.media.duration > 0
                ? "−" + root.timeText(Math.ceil(Math.max(0,
                    root.media.duration - root.displayPosition)))
                : "−0:00"
            color: "#9effffff"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Item {
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
                color: "#33ffffff"

                Rectangle {
                    width: parent.width * root.progressRatio
                    height: parent.height
                    radius: parent.radius
                    color: "#c7ffffff"
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(-width / 2, Math.min(parent.width - width / 2,
                        parent.width * root.progressRatio - width / 2))
                    width: trackMouse.pressed || trackMouse.containsMouse ? 12 : 0
                    height: width
                    radius: width / 2
                    color: "#ffffff"
                    Behavior on width { LockSpring { spring: 20 } }
                }
            }

            MouseArea {
                id: trackMouse
                anchors.fill: parent
                enabled: root.media.duration > 0
                hoverEnabled: true
                preventStealing: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                function updateRatio(pointerX) {
                    root.scrubRatio = Math.max(0, Math.min(1, pointerX / width))
                }
                onPressed: mouse => {
                    root.scrubbing = true
                    updateRatio(mouse.x)
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        updateRatio(mouse.x)
                }
                onReleased: mouse => {
                    updateRatio(mouse.x)
                    root.media.seekTo(root.scrubRatio * root.media.duration)
                    root.scrubbing = false
                }
                onCanceled: root.scrubbing = false
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 139
        spacing: 10

        TransportButton {
            glyph: "󰒮"
            glyphSize: 31
            buttonWidth: 62
            onTriggered: root.media.previous()
        }
        TransportButton {
            glyph: root.media.isPlaying ? "󰏤" : "󰐊"
            glyphSize: 38
            onTriggered: root.media.playPause()
        }
        TransportButton {
            glyph: "󰒭"
            glyphSize: 31
            buttonWidth: 62
            onTriggered: root.media.next()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 1
        border.color: "#46ffffff"
    }
}
