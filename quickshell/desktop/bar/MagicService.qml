pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool hasMagic: false

    Process {
        id: magicProc
        command: ["bash", "-c",
            "hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.workspace.name == \"special:magic\")' > /dev/null 2>&1 && echo 1 || echo 0"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.hasMagic = text.trim() === "1"
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: magicProc.running = true
    }
}
