pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int pct: 50

    function refresh() { refreshProc.running = true }
    function setPct(p) {
        let v = Math.max(1, Math.min(100, Math.round(p)))
        setProc.command = ["bash", "-c", "brightnessctl set " + v + "%"]
        setProc.running = true
        root.pct = v
    }

    Process {
        id: refreshProc
        command: ["bash", "-c",
            "max=$(brightnessctl max);" +
            "cur=$(brightnessctl get);" +
            "echo $((cur * 100 / max))"]
        stdout: StdioCollector {
            onStreamFinished: root.pct = parseInt(text.trim()) || 0
        }
    }

    Process { id: setProc; command: ["true"] }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: refreshProc.running = true
    }

    Component.onCompleted: refresh()
}
