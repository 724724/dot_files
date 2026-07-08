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
    property bool   artDark: true    // overall album-art brightness → text color

    readonly property bool hasMedia: status === "Playing" || status === "Paused"
    readonly property bool isPlaying: status === "Playing"

    function refresh() { if (!mediaProc.running) mediaProc.running = true }

    function playPause() {
        // Flip the status optimistically so the UI reacts instantly instead of
        // waiting for the next status read.
        if (status === "Playing") status = "Paused"
        else if (status === "Paused") status = "Playing"
        ctlProc.command = ["playerctl", "--player=playerctld", "play-pause"]; ctlProc.running = true
    }
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
                    root.status  = obj.status || "none"
                    root.title   = obj.title  || ""
                    root.artist  = obj.artist || ""
                    root.artUrl  = obj.artUrl || ""
                    root.artDark = obj.artDark !== false
                } catch (e) {}
            }
        }
    }

    Process { id: ctlProc; command: ["true"] }

    // Event-driven: playerctl --follow emits a line whenever the status or
    // track changes, and each line triggers one media-info.sh fetch — instant
    // updates instead of the old 1.5s blind poll (which spawned bash + 4×
    // playerctl + jq forever, even with nothing playing).
    Process {
        id: followProc
        command: ["playerctl", "--player=playerctld",
                  "metadata", "--format", "{{status}}|{{title}}", "--follow"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => followDebounce.restart()
        }
        // If playerctl/playerctld isn't available or dies, retry occasionally
        // rather than respawning in a tight loop.
        onExited: followRespawn.restart()
    }
    Timer { id: followDebounce; interval: 150; onTriggered: root.refresh() }
    Timer { id: followRespawn; interval: 5000; onTriggered: followProc.running = true }

    // Slow backstop: catches anything the follow stream misses (e.g. a player
    // that updates metadata without emitting a change).
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
