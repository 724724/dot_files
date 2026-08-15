pragma ComponentBehavior: Bound
import Quickshell.Widgets
import QtQuick

// Compact lock-local counterpart of the desktop bar media pill. It is kept
// deliberately effect-free: the tiny artwork quad and solid material avoid a
// persistent blur pass while the lock is visible.
Rectangle {
    id: root

    required property var equalizer
    required property var media
    property real preferredWidth: 420
    property bool shown: false

    signal activated()

    readonly property color accentBase: media.artAccent !== "" ? media.artAccent : "#b8f23d"
    readonly property real accentLuminance: 0.299 * accentBase.r + 0.587 * accentBase.g + 0.114 * accentBase.b
    readonly property color accent: accentLuminance < 0.48 ? Qt.lighter(accentBase, 1.8) : accentBase

    border.color: pillHover.hovered ? "#64ffffff" : "#3cffffff"
    border.width: 1
    color: pillHover.hovered ? "#f035353a" : "#ed2b2b2f"
    height: 40
    opacity: shown ? 1 : 0
    radius: 20
    scale: pillTap.pressed ? 0.975 : (shown ? 1 : 0.985)
    transformOrigin: Item.Center
    visible: shown || opacity > 0.002
    width: preferredWidth

    Behavior on border.color {
        ColorAnimation {
            duration: 100
        }
    }
    Behavior on color {
        ColorAnimation {
            duration: 100
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        LockSpring {
            epsilon: 0.001
            spring: 18
        }
    }

    ClippingRectangle {
        id: cover

        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        color: "#20ffffff"
        height: 24
        radius: 8
        width: 24

        Image {
            anchors.fill: parent
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            source: root.media.artUrl
            sourceSize.height: 48
            sourceSize.width: 48
        }
        Text {
            anchors.centerIn: parent
            color: "#c8ffffff"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 13
            text: "󰎈"
            visible: root.media.artUrl === ""
        }
    }
    Text {
        anchors.left: cover.right
        anchors.leftMargin: 9
        anchors.right: pillEq.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        color: "#ffffff"
        elide: Text.ElideRight
        font.family: "SF Pro Display"
        font.letterSpacing: 0.05
        font.pixelSize: 12
        font.weight: Font.Medium
        maximumLineCount: 1
        text: {
            const artist = String(root.media.artist || "");
            const title = String(root.media.title || "");
            return artist !== "" && title !== "" ? artist + "  •  " + title : title || artist || "Media";
        }
        textFormat: Text.PlainText
    }
    LockEqBars {
        id: pillEq

        anchors.right: parent.right
        anchors.rightMargin: 13
        anchors.verticalCenter: parent.verticalCenter
        active: root.media.isPlaying
        barColor: root.accent
        bars: 8
        barWidth: 2
        gap: 1
        levels: root.equalizer.levels
        maxHeight: 20
    }
    HoverHandler {
        id: pillHover

        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: pillTap

        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
