pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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

    // Event-driven: window opens/closes/moves (incl. to/from special:magic)
    // all emit Hyprland events, so poll only then — the old 1s blind timer
    // spawned bash+hyprctl+jq every second forever.
    Connections {
        target: Hyprland
        function onRawEvent(event) { debounce.restart() }
    }
    Timer { id: debounce; interval: 150; onTriggered: if (!magicProc.running) magicProc.running = true }

    // Slow backstop in case an event is ever missed.
    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: if (!magicProc.running) magicProc.running = true
    }
}
