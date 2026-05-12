pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var runningClasses: []
    property string focusedClass: ""
    // maps lowercase class → [{address, title, at, size}]
    property var clientsByClass: ({})

    readonly property var excludedClasses: ["xembedsniproxy", "xwaylandvideobridge", ""]

    Process {
        id: pollProc
        command: ["/home/sejunlee/.config/quickshell/desktop/dock/poll-clients.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(text.trim())
                    let excl = root.excludedClasses
                    let byClass = data.byClass || {}
                    root.clientsByClass = byClass
                    root.focusedClass = (data.focused || "").toLowerCase()
                    root.runningClasses = Object.keys(byClass).filter(c => c && !excl.includes(c))
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: if (!pollProc.running) pollProc.running = true
    }
    Component.onCompleted: pollProc.running = true
}
