pragma Singleton
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool micActive: false
    property bool micMuted: false
    property var micApps: []
    property string micName: "Microphone"
    property string error: ""

    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
    }
    readonly property string helper: _configDir + "/quickshell/scripts/privacy-status.py"

    function applyStatus(value) {
        if (!value || value.ok === false) {
            root.error = value && value.error ? value.error : "Microphone status unavailable"
            return
        }
        root.error = ""
        root.micActive = !!value.micActive
        root.micMuted = !!value.micMuted
        root.micApps = value.micApps || []
        root.micName = value.micName || "Microphone"
    }

    function parseOutput(text) {
        try { root.applyStatus(JSON.parse((text || "").trim())) }
        catch (e) { root.error = "Invalid microphone status" }
    }

    function refresh() {
        if (!refreshProcess.running) refreshProcess.running = true
    }

    Process {
        id: refreshProcess
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { onStreamFinished: root.parseOutput(text) }
    }

    Process {
        // Event-driven only: no camera device watcher and no periodic polling.
        command: ["setpriv", "--pdeathsig", "TERM", "--",
                  "python3", root.helper, "monitor", "0.5"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.parseOutput(data)
        }
    }

    IpcHandler {
        target: "privacy"
        function refresh() { root.refresh() }
        function getstate(): string {
            return JSON.stringify({
                micActive: root.micActive,
                micMuted: root.micMuted,
                micApps: root.micApps,
                error: root.error
            })
        }
    }
}
