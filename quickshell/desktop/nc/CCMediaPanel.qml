import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

Item {
    id: root
    required property var mediaService
    readonly property bool dark: ThemeService.isDark

    readonly property string status: mediaService ? mediaService.status : "none"
    readonly property string title: mediaService ? mediaService.title : ""
    readonly property string artist: mediaService ? mediaService.artist : ""
    readonly property string artUrl: mediaService ? mediaService.artUrl : ""

    readonly property bool hasMedia: status === "Playing" || status === "Paused"
    readonly property bool isPlaying: status === "Playing"

    implicitHeight: 60
    scale: panelMa.pressed ? 0.985 : 1
    Behavior on scale { AppleSpring { spring: 13 } }

    function _ctl(cmd) {
        if (!mediaService) return
        if (cmd === "previous") mediaService.prev()
        else if (cmd === "play-pause") mediaService.playPause()
        else if (cmd === "next") mediaService.next()
    }

    // Raises the currently-playing app's window (Spotify, browser, …). Resolves
    // the active player's process via D-Bus and maps it to a Hyprland window by
    // PID — see focus-media-player.sh.
    Process {
        id: focusProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/focus-media-player.sh"]
    }

    // Whole-panel click target — raises the playing app's window and closes the
    // control center. Declared before the art/text/controls so it sits beneath
    // them: the transport buttons' own MouseAreas grab their clicks first,
    // leaving the art, title and empty space to focus the app. Disabled when
    // nothing is playing so there's no window to raise (and no pointer cursor).
    MouseArea {
        id: panelMa
        anchors.fill: parent
        enabled: root.hasMedia
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            focusProc.running = true
            NcServer.controlCenterVisible = false
        }
    }

    // Album art — ClippingRectangle so the cover image's corners are
    // actually rounded (a plain Rectangle with clip:true clips to the
    // bounding box only).
    ClippingRectangle {
        id: artBox
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: 48; height: 48
        radius: 8
        color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)

        Image {
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            visible: root.artUrl !== ""
            asynchronous: true
            smooth: true
        }

        Text {
            anchors.centerIn: parent
            text: ""
            color: dark ? "#9aa0a6" : "#5f6368"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 20
            visible: root.artUrl === ""
        }
    }

    Column {
        anchors {
            left: artBox.right
            leftMargin: 12
            right: controls.left
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        spacing: 2

        Text {
            text: root.hasMedia ? root.title : "Not Playing"
            color: dark ? "#f5f6f8" : "#1c1c1e"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            text: root.artist
            color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            visible: text !== ""
            elide: Text.ElideRight
            width: parent.width
        }
    }

    Row {
        id: controls
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        spacing: 4
        visible: root.hasMedia

        Repeater {
            model: [
                { icon: "󰒮", cmd: "previous" },
                { icon: root.isPlaying ? "󰏤" : "󰐊", cmd: "play-pause" },
                { icon: "󰒭", cmd: "next" }
            ]
            delegate: Rectangle {
                required property var modelData
                width: 32; height: 32
                radius: 16
                scale: ma2.pressed ? 0.90 : 1
                Behavior on scale { AppleSpring { spring: 13 } }
                color: ma2.containsMouse
                    ? (dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.06))
                    : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: modelData.icon
                    color: dark ? "#f0f3f6" : "#1c1c1e"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: ma2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._ctl(modelData.cmd)
                }
            }
        }
    }
}
