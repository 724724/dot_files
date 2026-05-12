pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int notifCount: 0
    property bool dnd: false

    Process {
        id: pollProc
        command: ["qs", "ipc", "-c", "desktop", "call", "nc", "getstate"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let obj = JSON.parse(text.trim())
                    root.notifCount = obj.count || 0
                    root.dnd = obj.dnd === true
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: pollProc.running = true
    }

    Component.onCompleted: pollProc.running = true
}
