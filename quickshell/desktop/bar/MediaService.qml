pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string status: "none"   // "Playing" | "Paused" | "none"
    property string title: ""
    property string artist: ""
    property string artUrl: ""

    readonly property bool hasMedia: status === "Playing" || status === "Paused"
    readonly property bool isPlaying: status === "Playing"

    function refresh() { mediaProc.running = true }

    function playPause() { ctlProc.command = ["playerctl", "--player=playerctld", "play-pause"]; ctlProc.running = true }
    function next()      { ctlProc.command = ["playerctl", "--player=playerctld", "next"];       ctlProc.running = true }
    function prev()      { ctlProc.command = ["playerctl", "--player=playerctld", "previous"];   ctlProc.running = true }

    Process {
        id: mediaProc
        command: ["/home/sejunlee/.config/hypr/scripts/media-info.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let line = text.trim()
                if (!line) return
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

    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: if (!mediaProc.running) mediaProc.running = true
    }
}
