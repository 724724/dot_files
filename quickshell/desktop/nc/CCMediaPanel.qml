import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

Item {
    id: root
    readonly property bool dark: ThemeService.isDark

    property string status: "none"
    property string title: ""
    property string artist: ""
    property string artUrl: ""

    readonly property bool hasMedia: status === "Playing" || status === "Paused"
    readonly property bool isPlaying: status === "Playing"

    implicitHeight: 60

    function refresh() { mediaProc.running = true }

    Process {
        id: mediaProc
        command: ["/home/sejunlee/.config/hypr/scripts/media-info.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let line = text.trim()
                if (!line) { root.status = "none"; return }
                try {
                    let obj = JSON.parse(line)
                    root.status = obj.status || "none"
                    root.title  = obj.title  || ""
                    root.artist = obj.artist || ""
                    root.artUrl = obj.artUrl || ""
                } catch (e) {}
            }
        }
    }

    Process { id: ctlProc; command: ["true"] }
    function _ctl(cmd) {
        ctlProc.command = ["playerctl", "--player=playerctld", cmd]
        ctlProc.running = true
    }

    // Raises the currently-playing app's window (Spotify, browser, …). Resolves
    // the active player's process via D-Bus and maps it to a Hyprland window by
    // PID — see focus-media-player.sh.
    Process {
        id: focusProc
        command: ["/home/sejunlee/.config/hypr/scripts/focus-media-player.sh"]
    }

    // Poll only while the control center is actually on screen — this panel
    // lives inside the always-loaded (but usually hidden) CC window, and its
    // unconditional 1.5s poll duplicated MediaService's fetch around the clock.
    // triggeredOnStart refreshes immediately when the CC opens.
    Timer {
        interval: 1500
        running: NcServer.controlCenterVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!mediaProc.running) mediaProc.running = true
    }

    // Whole-panel click target — raises the playing app's window and closes the
    // control center. Declared before the art/text/controls so it sits beneath
    // them: the transport buttons' own MouseAreas grab their clicks first,
    // leaving the art, title and empty space to focus the app. Disabled when
    // nothing is playing so there's no window to raise (and no pointer cursor).
    MouseArea {
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
                color: ma2.containsMouse
                    ? (dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.06))
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

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
