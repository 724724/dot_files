pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool enabled: false

    property bool vocals: true
    property bool drums: true
    property bool bass: true
    property bool other: true
    // "speed" | "quality"
    property string mode: "speed"

    property bool preparing: false
    property string processorState: "off"
    property string processorError: ""
    property int generation: 0

    property bool _pausedByUs: false
    property bool _completed: false
    property bool _expectedExit: false
    property bool _restartPending: false
    property string _pendingPlayerAction: ""
    property string _runningPlayerAction: ""

    property bool popupOpen: false
    property real popupAnchorX: 0
    property var popupScreen: null

    readonly property bool anyMuted: !vocals || !drums || !bass || !other
    readonly property bool active: enabled && MediaService.hasMedia
    readonly property int mutedCount:
        (vocals ? 0 : 1) + (drums ? 0 : 1) + (bass ? 0 : 1) + (other ? 0 : 1)

    readonly property string controlPath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-stems.json"

    FileView {
        id: controlStore
        path: root.controlPath
        printErrors: false
    }

    function _publish() {
        controlStore.setText(JSON.stringify({
            vocals: root.vocals, drums: root.drums,
            bass: root.bass, other: root.other,
            mode: root.mode, generation: root.generation
        }))
    }

    onVocalsChanged: _publish()
    onDrumsChanged: _publish()
    onBassChanged: _publish()
    onOtherChanged: _publish()

    onModeChanged: {
        if (!root._completed) return
        if (root.active) {
            root._expectedExit = true
            root.generation++
            root._beginPrepare()
            root.processorState = "starting"
            root.processorError = ""
            root._restartPending = true
        }
        _publish()
        if (root.active) root._terminateProcessor()
    }

    onActiveChanged: {
        if (!root._completed) return
        if (root.active) {
            root.generation++
            root._publish()
            root._launchProcessor()
        } else {
            root.generation++
            root._publish()
            root._stopProcessor()
        }
    }

    onEnabledChanged: {
        if (enabled && MediaService.transpose !== 0)
            MediaService.setTranspose(0)
    }

    Process {
        id: playerProc
        command: ["true"]
        onExited: {
            root._runningPlayerAction = ""
            if (root._pendingPlayerAction === "") return
            let action = root._pendingPlayerAction
            root._pendingPlayerAction = ""
            root._player(action)
        }
    }
    function _player(action) {
        if (playerProc.running) {
            root._pendingPlayerAction = action
            return
        }
        root._runningPlayerAction = action
        playerProc.command = ["playerctl", "--player=playerctld", action]
        playerProc.running = true
    }

    function _beginPrepare() {
        root.preparing = true
        prepareTimeout.restart()
        if (!root._pausedByUs
                && (MediaService.isPlaying
                    || root._runningPlayerAction === "play"
                    || root._pendingPlayerAction === "play")) {
            root._pausedByUs = true
            root._player("pause")
        }
    }
    function _finishPrepare() {
        if (!root.preparing) return
        root.preparing = false
        prepareTimeout.stop()
        if (root._pausedByUs) {
            root._pausedByUs = false
            root._player("play")
        }
    }

    function _processorCommand() {
        let customVenv = Quickshell.env("QS_STEM_VENV")
        let venv = customVenv && customVenv !== ""
            ? customVenv
            : Quickshell.env("HOME") + "/.local/share/quickshell/stem-venv"
        return ["setpriv", "--pdeathsig", "TERM", "--",
                venv + "/bin/python",
                Quickshell.env("HOME") + "/.config/quickshell/scripts/stem-split.py",
                "--mode", root.mode, "--generation", String(root.generation)]
    }

    function _launchProcessor() {
        root.processorState = "starting"
        root.processorError = ""
        root._beginPrepare()
        if (stemProc.running) {
            root._restartPending = true
            root._terminateProcessor()
            return
        }
        root._restartPending = false
        root._expectedExit = false
        stemProc.command = root._processorCommand()
        stemProc.running = true
    }

    function _terminateProcessor() {
        if (!stemProc.running) {
            stopTimeout.stop()
            if (root._restartPending && root.active) restartDelay.restart()
            return
        }
        root._expectedExit = true
        stemProc.signal(15)
        stopTimeout.restart()
    }

    function _stopProcessor() {
        root._restartPending = false
        root.processorState = "off"
        root.processorError = ""
        root._finishPrepare()
        root._terminateProcessor()
    }

    function _matchesSession(message) {
        if (message.generation !== undefined
                && String(message.generation) !== String(root.generation))
            return false
        if (message.mode !== undefined && message.mode !== root.mode)
            return false
        return true
    }

    function _markReady() {
        if (!root.active || root._expectedExit
                || root.processorState !== "starting")
            return
        root.processorState = "ready"
        root.processorError = ""
        root._finishPrepare()
    }

    function _failProcessor(message) {
        if (!root.active) return
        root.processorState = "error"
        root.processorError = message || "Stem Filter could not start."
        root._restartPending = false
        root._finishPrepare()
        root._terminateProcessor()
    }

    function _readProcessorLine(data) {
        let line = data.trim()
        if (line === "") return
        let message
        try {
            message = JSON.parse(line)
        } catch (e) {
            if (line.startsWith("ERROR:"))
                root._failProcessor(line.slice(6).trim())
            return
        }
        if (!message || !root._matchesSession(message)) return
        let event = message.event || message.type || message.status
        if (event === "ready") root._markReady()
        else if (event === "error")
            root._failProcessor(message.message || message.error)
    }

    function _processorExited(exitCode) {
        stopTimeout.stop()
        let expected = root._expectedExit
        root._expectedExit = false
        if (expected) {
            if (root._restartPending && root.active) restartDelay.restart()
            return
        }
        if (!root.active) {
            root.processorState = "off"
            root._finishPrepare()
            return
        }
        root._failProcessor(exitCode === 0
            ? "Stem Filter stopped unexpectedly."
            : "Stem Filter exited with code " + exitCode + ".")
    }

    Timer {
        id: prepareTimeout
        interval: 45000
        onTriggered: root._failProcessor("Stem Filter took too long to start.")
    }

    Timer {
        id: restartDelay
        interval: 120
        onTriggered: {
            if (root._restartPending && root.active && !stemProc.running)
                root._launchProcessor()
        }
    }

    Timer {
        id: stopTimeout
        interval: 12000
        onTriggered: {
            if (stemProc.running && root._expectedExit) stemProc.signal(9)
        }
    }

    Component.onCompleted: {
        root._completed = true
        root._publish()
        if (root.active) {
            root.generation++
            root._publish()
            root._launchProcessor()
        }
    }

    function toggle(stem) {
        if (stem === "vocals") root.vocals = !root.vocals
        else if (stem === "drums") root.drums = !root.drums
        else if (stem === "bass") root.bass = !root.bass
        else if (stem === "other") root.other = !root.other
    }

    function setMode(value) {
        if (value === "speed" || value === "quality") root.mode = value
    }

    readonly property string segment: enabled ? mode : "off"
    function setSegment(value) {
        if (value === "off") { root.enabled = false; return }
        if (value !== "speed" && value !== "quality") return
        root.mode = value
        root.enabled = true
    }

    function enableAll() {
        root.vocals = true
        root.drums = true
        root.bass = true
        root.other = true
    }

    Process {
        id: stemProc
        running: false
        command: root._processorCommand()
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._readProcessorLine(data)
        }
        onExited: (exitCode, exitStatus) => root._processorExited(exitCode)
    }
}
