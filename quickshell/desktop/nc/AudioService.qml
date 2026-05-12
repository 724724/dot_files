pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int vol: 0
    property bool muted: false

    function refresh() { refreshProc.running = true }
    function setVolume(p) { setProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", p + "%"]; setProc.running = true }
    function toggleMute() { muteProc.running = true }

    Process {
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("'change' on sink") || data.includes("'change' on server"))
                    root.refresh()
            }
        }
    }

    Process {
        id: refreshProc
        command: ["bash", "-c",
            "vol=$(pactl get-sink-volume @DEFAULT_SINK@ | awk '/Volume:/{gsub(/%/,\"\",$5); print $5}');" +
            "mute=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}');" +
            "echo \"$vol $mute\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = text.trim().split(" ")
                root.vol = parseInt(parts[0]) || 0
                root.muted = parts[1] === "yes"
            }
        }
    }

    Process { id: setProc; command: ["true"] }
    Process {
        id: muteProc
        command: ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
    }

    Component.onCompleted: refresh()
}
