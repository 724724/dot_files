pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var runningClasses: []
    property string focusedClass: ""
    // maps lowercase class → [{address, title, at, size, ws}]
    property var clientsByClass: ({})
    // Active workspace id on the focused monitor — used to un-hide windows back
    // onto whatever workspace is currently in view (see DockItem restore).
    property int activeWs: -1

    // macOS "Turn Hiding Off": when true every dock stays permanently revealed.
    // Toggled by Super+V via the IpcHandler below; persisted across restarts.
    property bool pinnedVisible: false

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
                    root.activeWs = (typeof data.activeWs === "number") ? data.activeWs : -1
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

    Component.onCompleted: {
        pollProc.running = true
        root.pinnedVisible = (visStore.text().trim() === "1")
    }

    // Persist the always-visible toggle (same blockLoading FileView convention
    // the rest of the shell uses).
    FileView {
        id: visStore
        path: Quickshell.stateDir + "/dock-pinned-visible.txt"
        blockLoading: true
        printErrors: false
    }

    function setPinnedVisible(v) {
        root.pinnedVisible = v
        visStore.setText(v ? "1" : "0")
    }

    IpcHandler {
        target: "dock"
        function toggle() { root.setPinnedVisible(!root.pinnedVisible) }
        function show()   { root.setPinnedVisible(true) }
        function hide()   { root.setPinnedVisible(false) }
    }
}
