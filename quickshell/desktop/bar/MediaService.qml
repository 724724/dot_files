pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string status: "none"   // "Playing" | "Paused" | "none"
    property string title: ""
    property string artist: ""
    property string artUrl: ""
    property string mediaUrl: ""
    property bool   artDark: true    // overall album-art brightness → text color
    property string artAccent: ""    // most vivid colour in the cover (EQ tint)
    property real position: 0
    property real duration: 0
    property int transpose: 0
    property string pitchState: "off"
    property string pitchError: ""
    property bool _expectedPitchExit: false

    property bool popupOpen: false
    property real popupAnchorX: 0
    property var popupScreen: null
    property real _ignorePositionUntil: 0
    property int _positionTicks: 0
    property bool _mediaRefreshPending: false
    property int _timelineBootstrapAttempts: 0
    property string _trackKey: ""
    property string _durationRequestUrl: ""

    readonly property bool hasMedia: status === "Playing" || status === "Paused"
    readonly property bool isPlaying: status === "Playing"
    readonly property string pitchControlPath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-pitch.json"

    FileView {
        id: pitchControlStore
        path: root.pitchControlPath
        printErrors: false
    }

    readonly property string mediaInfoPath:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/media-info.py"

    function refresh() {
        if (mediaProc.running) {
            _mediaRefreshPending = true
            return
        }
        _mediaRefreshPending = false
        mediaProc.running = true
    }
    function refreshPosition() {
        if (hasMedia && !positionProc.running) positionProc.running = true
    }
    function refreshDuration() {
        if (!hasMedia || durationProc.running) return
        _durationRequestUrl = mediaUrl
        durationProc.command = [mediaInfoPath, "duration", "--url", mediaUrl]
        durationProc.running = true
    }
    function refreshTimeline() {
        refreshPosition()
        refreshDuration()
    }
    function bootstrapTimeline() {
        if (!hasMedia) return
        _timelineBootstrapAttempts = 0
        refreshTimeline()
        timelineBootstrap.restart()
    }
    function applySnapshot(obj) {
        let nextStatus = obj.status || "none"
        let nextTitle = obj.title || ""
        let nextArtist = obj.artist || ""
        let nextUrl = obj.url || ""
        let nextKey = nextUrl !== ""
            ? nextUrl : nextTitle + "\u001f" + nextArtist
        let changed = nextKey !== "" && nextKey !== _trackKey
        let nextDuration = Number(obj.duration || 0)
        let nextPosition = Number(obj.position || 0)

        if (changed) {
            _trackKey = nextKey
            position = isFinite(nextPosition) && nextPosition > 0
                ? nextPosition : 0
            duration = isFinite(nextDuration) && nextDuration > 0
                ? nextDuration : 0
            artUrl = obj.artUrl || ""
            artDark = obj.artDark !== false
            artAccent = obj.artAccent || ""
        } else {
            if (obj.artUrl) artUrl = obj.artUrl
            if (isFinite(nextDuration) && nextDuration > 0)
                duration = nextDuration
            if (isFinite(nextPosition) && nextPosition > 0
                    && Date.now() >= _ignorePositionUntil)
                position = duration > 0
                    ? Math.min(nextPosition, duration) : nextPosition
            if (obj.artAccent) artAccent = obj.artAccent
        }

        status = nextStatus
        title = nextTitle
        artist = nextArtist
        mediaUrl = nextUrl

        if (!hasMedia) {
            artUrl = ""
            mediaUrl = ""
            _trackKey = ""
        } else if (changed) {
            bootstrapTimeline()
        }
    }

    function playPause() {
        // Flip the status optimistically so the UI reacts instantly instead of
        // waiting for the next status read.
        if (status === "Playing") status = "Paused"
        else if (status === "Paused") status = "Playing"
        ctlProc.command = ["playerctl", "--player=playerctld", "play-pause"]; ctlProc.running = true
    }
    function next() {
        position = 0
        ctlProc.command = ["playerctl", "--player=playerctld", "next"]
        ctlProc.running = true
        timelineRefreshDelay.restart()
    }
    function prev() {
        position = 0
        ctlProc.command = ["playerctl", "--player=playerctld", "previous"]
        ctlProc.running = true
        timelineRefreshDelay.restart()
    }
    function seekTo(seconds) {
        if (duration <= 0) return
        let target = Math.max(0, Math.min(duration, Number(seconds)))
        position = target
        _ignorePositionUntil = Date.now() + 900
        seekProc.command = ["playerctl", "--player=playerctld",
                            "position", target.toFixed(3)]
        seekProc.running = true
    }
    function _publishTranspose() {
        pitchControlStore.setText(JSON.stringify({
            semitones: transpose,
            updatedAt: Date.now()
        }))
    }
    function _launchPitch() {
        if (transpose === 0 || pitchProc.running) return
        pitchState = "starting"
        pitchError = ""
        _expectedPitchExit = false
        pitchProc.command = [
            "setpriv", "--pdeathsig", "TERM", "--",
            Quickshell.env("HOME")
                + "/.config/quickshell/scripts/pitch-shifter.py",
            "--semitones", String(transpose),
            "--engine", "rubberband-live"
        ]
        pitchProc.running = true
    }
    function _stopPitch() {
        pitchLaunchDelay.stop()
        if (!pitchProc.running) {
            pitchState = "off"
            return
        }
        _expectedPitchExit = true
        pitchProc.signal(15)
        pitchStopTimeout.restart()
    }
    function setTranspose(value) {
        let nextValue = Math.max(-12, Math.min(12, Math.round(value)))
        if (nextValue === transpose) return
        let stoppingStems = nextValue !== 0 && StemService.enabled
        if (stoppingStems) StemService.enabled = false
        transpose = nextValue
        _publishTranspose()
        if (transpose === 0) {
            if (!pitchProc.running) _stopPitch()
        } else if (!pitchProc.running) {
            pitchLaunchDelay.interval = stoppingStems ? 550 : 1
            pitchLaunchDelay.restart()
        }
    }
    function transposeBy(semitones) {
        setTranspose(transpose + semitones)
    }
    function _readPitchEvent(data) {
        let line = data.trim()
        if (line === "") return
        try {
            let message = JSON.parse(line)
            if (message.event === "ready"
                    || message.event === "transpose") {
                pitchState = "ready"
                pitchError = ""
            } else if (message.event === "error") {
                pitchState = "error"
                pitchError = message.message || "Pitch shifter unavailable."
            }
        } catch (error) {}
    }

    onPopupOpenChanged: {
        if (popupOpen) refreshTimeline()
    }
    onHasMediaChanged: {
        if (!hasMedia) {
            popupOpen = false
            position = 0
            duration = 0
            timelineBootstrap.stop()
            if (transpose !== 0) {
                transpose = 0
                _publishTranspose()
            }
            _stopPitch()
        }
    }
    Process {
        id: mediaProc
        command: [root.mediaInfoPath]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let line = text.trim()
                if (!line) return
                try {
                    root.applySnapshot(JSON.parse(line))
                } catch (e) {}
            }
        }
        onExited: Qt.callLater(function() {
            if (root._mediaRefreshPending) root.refresh()
        })
    }

    Process { id: ctlProc; command: ["true"] }
    Process { id: seekProc; command: ["true"] }

    Process {
        id: pitchProc
        running: false
        command: ["true"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._readPitchEvent(data)
        }
        onExited: (exitCode, exitStatus) => {
            pitchStopTimeout.stop()
            let expected = root._expectedPitchExit
            root._expectedPitchExit = false
            if (expected || root.transpose === 0) {
                root.pitchState = "off"
                root.pitchError = ""
                return
            }
            root.pitchState = "error"
            if (root.pitchError === "")
                root.pitchError = "Pitch shifter exited with code "
                    + exitCode + "."
        }
    }

    Process {
        id: positionProc
        command: ["playerctl", "--player=playerctld", "position"]
        stdout: StdioCollector {
            onStreamFinished: {
                let value = Number(text.trim())
                if (isFinite(value) && value >= 0
                        && Date.now() >= root._ignorePositionUntil
                        && (value > 0.05 || root.position < 0.75
                            || !root.isPlaying))
                    root.position = root.duration > 0
                        ? Math.min(value, root.duration) : value
            }
        }
    }

    Process {
        id: durationProc
        command: [root.mediaInfoPath, "duration", "--url", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let obj = JSON.parse(text.trim())
                    if (root._durationRequestUrl !== root.mediaUrl) return
                    let value = Number(obj.duration || 0)
                    if (isFinite(value) && value > 0) {
                        root.duration = value
                        root.position = Math.min(root.position, value)
                    }
                    if (root.artUrl === "" && obj.thumbnail)
                        root.artUrl = obj.thumbnail
                } catch (e) {}
            }
        }
    }

    Timer {
        id: timelineRefreshDelay
        interval: 350
        onTriggered: root.refreshTimeline()
    }

    Timer {
        id: timelineBootstrap
        interval: 350
        repeat: true
        onTriggered: {
            root._timelineBootstrapAttempts++
            root.refreshTimeline()
            if (root.duration > 0 || root._timelineBootstrapAttempts >= 8)
                stop()
        }
    }

    Timer {
        id: pitchLaunchDelay
        interval: 1
        onTriggered: root._launchPitch()
    }

    Timer {
        id: pitchStopTimeout
        interval: 3000
        onTriggered: {
            if (pitchProc.running && root._expectedPitchExit)
                pitchProc.signal(9)
        }
    }

    Timer {
        interval: root.popupOpen ? 250 : 1000
        running: root.hasMedia
        repeat: true
        onTriggered: {
            if (root.isPlaying) {
                let nextPosition = root.position + interval / 1000
                root.position = root.duration > 0
                    ? Math.min(root.duration, nextPosition) : nextPosition
            }
            if (!root.popupOpen) return
            root._positionTicks++
            if (root._positionTicks % 4 === 0) root.refreshPosition()
            if ((root.duration <= 0 && root._positionTicks % 4 === 0)
                    || root._positionTicks % 20 === 0)
                root.refreshDuration()
        }
    }

    // Event-driven: playerctl --follow emits a line whenever the status or
    // track changes, and each line triggers one lightweight media snapshot.
    Process {
        id: followProc
        command: ["setpriv", "--pdeathsig", "TERM", "--",
                  "playerctl", "--player=playerctld",
                  "metadata", "--format", "{{status}}|{{title}}", "--follow"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                followDebounce.restart()
                root.refreshTimeline()
            }
        }
        // If playerctl/playerctld isn't available or dies, retry occasionally
        // rather than respawning in a tight loop.
        onExited: followRespawn.restart()
    }
    Timer { id: followDebounce; interval: 150; onTriggered: root.refresh() }
    Timer { id: followRespawn; interval: 5000; onTriggered: followProc.running = true }

    // Slow backstop: catches anything the follow stream misses (e.g. a player
    // that updates metadata without emitting a change).
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root._publishTranspose()
}
