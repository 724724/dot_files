pragma Singleton
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool micActive: false
    property bool micMuted: false
    property var micApps: []
    property string micName: "Microphone"
    property bool cameraActive: false
    property var cameraApps: []
    property string cameraName: "Camera"
    property bool cameraPopupOpen: false
    property real cameraPopupAnchorX: 0
    property var cameraPopupScreen: null
    // Mic Mode sheet, opened from the bar's mic indicator.
    property bool micModeOpen: false
    property real micModeAnchorX: 0
    property var micModeScreen: null
    // Name of the app currently holding the mic, "" when we can't identify one.
    readonly property string micAppName: {
        let a = root.micApps
        return (a && a.length > 0 && a[0] && a[0].name) ? String(a[0].name) : ""
    }
    readonly property string cameraAppName: {
        let a = root.cameraApps
        return (a && a.length > 0 && a[0] && a[0].name) ? String(a[0].name) : ""
    }
    property string error: ""

    onCameraActiveChanged: if (!cameraActive) cameraPopupOpen = false

    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
    }
    readonly property string helper: _configDir + "/quickshell/scripts/privacy-status.py"

    function applyStatus(value) {
        if (!value || value.ok === false) {
            root.error = value && value.error ? value.error : "Privacy status unavailable"
            return
        }
        root.error = ""
        root.micActive = !!value.micActive
        root.micMuted = !!value.micMuted
        root.micApps = value.micApps || []
        root.micName = value.micName || "Microphone"
        root.cameraActive = !!value.cameraActive
        root.cameraApps = value.cameraApps || []
        root.cameraName = value.cameraName || "Camera"
    }

    function parseOutput(text) {
        try { root.applyStatus(JSON.parse((text || "").trim())) }
        catch (e) { root.error = "Invalid privacy status" }
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
        // PipeWire/Pulse events plus a lightweight direct V4L2 ownership check.
        command: ["setpriv", "--pdeathsig", "TERM", "--",
                  "python3", root.helper, "monitor", "0.5", "virtual-v1"]
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
                cameraActive: root.cameraActive,
                cameraApps: root.cameraApps,
                error: root.error
            })
        }
    }
}
