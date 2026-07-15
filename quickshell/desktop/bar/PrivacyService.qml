pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool micActive: false
    property bool micMuted: false
    property var micApps: []
    property string micName: "Microphone"
    property bool cameraActive: false
    property var cameraApps: []
    property string cameraName: "Camera"
    property bool cameraAvailable: false
    property bool cameraUsingVirtual: false
    property bool cameraPreviewAvailable: false
    property string cameraPreviewName: ""
    property bool voiceIsolationAvailable: false
    property string micMode: "standard"
    property bool portraitAvailable: false
    property bool portraitEnabled: false
    property bool backgroundAvailable: false
    property string backgroundMode: "none"
    property string backgroundValue: ""
    property string backgroundImage: ""
    property string error: ""
    property bool busy: false
    property bool popupVisible: false
    property var targetScreen: null
    property real anchorX: 0

    Timer {
        id: cameraInactiveDelay
        interval: 700
        onTriggered: if (!root.cameraActive) root.popupVisible = false
    }

    readonly property var cameraApp: cameraApps.length > 0 ? cameraApps[0] : ({})
    readonly property string cameraAppName: cameraApp.name || "Camera in use"
    readonly property string cameraAppId: cameraApp.id || "camera-web"
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
        root.cameraAvailable = !!value.cameraAvailable
        root.cameraUsingVirtual = !!value.cameraUsingVirtual
        root.cameraPreviewAvailable = !!value.cameraPreviewAvailable
        root.cameraPreviewName = value.cameraPreviewName || ""
        root.voiceIsolationAvailable = !!value.voiceIsolationAvailable
        root.micMode = value.micMode || "standard"
        root.portraitAvailable = !!value.portraitAvailable
        root.portraitEnabled = !!value.portraitEnabled
        root.backgroundAvailable = !!value.backgroundAvailable
        root.backgroundMode = value.backgroundMode || "none"
        root.backgroundValue = value.backgroundValue || ""
        root.backgroundImage = value.backgroundImage || ""
        if (root.cameraActive) cameraInactiveDelay.stop()
        else if (root.popupVisible) cameraInactiveDelay.restart()
    }

    function parseOutput(text) {
        try { root.applyStatus(JSON.parse((text || "").trim())) }
        catch (e) { root.error = "Invalid privacy status" }
    }

    function refresh() {
        if (!refreshProcess.running && !root.busy) refreshProcess.running = true
    }

    function setMicMode(mode) {
        if (root.busy || (mode !== "standard" && mode !== "voice-isolation")) return
        actionProcess.command = ["python3", root.helper, "mic-mode", mode]
        root.busy = true
        actionProcess.running = true
    }

    function setPortrait(enabled) {
        if (root.busy || !root.portraitAvailable) return
        actionProcess.command = ["python3", root.helper, "effect", "portrait", enabled ? "true" : "false"]
        root.busy = true
        actionProcess.running = true
    }

    function setBackground(mode, value) {
        if (root.busy || !root.backgroundAvailable) return
        actionProcess.command = ["python3", root.helper, "effect", "background", mode + ":" + (value || "")]
        root.busy = true
        actionProcess.running = true
    }

    Process {
        id: refreshProcess
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { onStreamFinished: root.parseOutput(text) }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector { onStreamFinished: root.parseOutput(text) }
        onExited: {
            root.busy = false
            root.refresh()
        }
    }

    Process {
        command: ["python3", root.helper, "monitor", "0.5"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.parseOutput(data)
        }
    }

    IpcHandler {
        target: "privacy"
        function refresh() { root.refresh() }
        function hide() { root.popupVisible = false }
    }
}
