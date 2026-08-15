import Quickshell
import Quickshell.Io
import QtQuick

// Display-only spectrum capture for the lock media surfaces. No microphone or
// stem controls are exposed; audio-eq.py reads the default sink monitor.
Scope {
    id: root

    required property var media
    property bool enabled: true
    property var levels: []
    readonly property bool active: enabled && media.hasMedia && media.isPlaying

    Process {
        id: eqProcess
        running: root.active
        command: ["/usr/bin/setpriv", "--pdeathsig", "TERM", "--",
                  "/usr/bin/python3",
                  Quickshell.env("HOME")
                      + "/.config/quickshell/scripts/audio-eq.py"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!root.active)
                    return
                try {
                    const next = JSON.parse(data)
                    if (Array.isArray(next) && next.length > 0)
                        root.levels = next.slice(0, 8)
                } catch (error) {}
            }
        }
    }

    onActiveChanged: if (!root.active) root.levels = []
}
