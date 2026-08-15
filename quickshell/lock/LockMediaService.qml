import Quickshell
import Quickshell.Io
import QtQuick

// Lock-local media controller. It intentionally shares no QML singleton or IPC
// endpoint with the desktop shell and exposes no stem or pitch functionality.
Scope {
    id: root

    property string status: "none"
    property string title: ""
    property string artist: ""
    property string artUrl: ""
    property string mediaUrl: ""
    property bool artDark: true
    property string artAccent: ""
    property real position: 0
    property real duration: 0
    property bool detailedVisible: false
    property bool enabled: true

    property real _ignorePositionUntil: 0
    property int _positionTicks: 0
    property bool _mediaRefreshPending: false
    property int _timelineBootstrapAttempts: 0
    property string _trackKey: ""
    property string _durationRequestUrl: ""

    readonly property bool hasMedia: status === "Playing" || status === "Paused"
    readonly property bool isPlaying: status === "Playing"
    readonly property string mediaInfoPath:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/media-info.py"

    function safeText(value, limit) {
        return String(value || "").slice(0, limit)
    }

    function safeArtUrl(value) {
        const url = String(value || "").trim()
        if (url.startsWith("file://")
                || url.startsWith("https://")
                || url.startsWith("http://")) {
            return url.slice(0, 4096)
        }
        return ""
    }

    function refresh() {
        if (!root.enabled)
            return
        if (mediaProc.running) {
            root._mediaRefreshPending = true
            return
        }
        root._mediaRefreshPending = false
        mediaProc.running = true
    }

    function refreshPosition() {
        if (root.enabled && root.hasMedia && !positionProc.running)
            positionProc.running = true
    }

    function refreshDuration() {
        if (!root.hasMedia || durationProc.running)
            return
        root._durationRequestUrl = root.mediaUrl
        durationProc.command = ["/usr/bin/setpriv", "--pdeathsig", "TERM", "--",
                                "/usr/bin/python3", root.mediaInfoPath,
                                "duration", "--url", root.mediaUrl]
        durationProc.running = true
    }

    function refreshTimeline() {
        root.refreshPosition()
        root.refreshDuration()
    }

    function bootstrapTimeline() {
        if (!root.hasMedia)
            return
        root._timelineBootstrapAttempts = 0
        root.refreshTimeline()
        timelineBootstrap.restart()
    }

    function applySnapshot(object) {
        const nextStatus = object.status || "none"
        const nextTitle = root.safeText(object.title, 512)
        const nextArtist = root.safeText(object.artist, 512)
        const nextUrl = root.safeText(object.url, 4096)
        const nextKey = nextUrl !== ""
            ? nextUrl : nextTitle + "\u001f" + nextArtist
        const changed = nextKey !== "" && nextKey !== root._trackKey
        const nextDuration = Number(object.duration || 0)
        const nextPosition = Number(object.position || 0)

        if (changed) {
            root._trackKey = nextKey
            root.position = isFinite(nextPosition) && nextPosition > 0
                ? nextPosition : 0
            root.duration = isFinite(nextDuration) && nextDuration > 0
                ? nextDuration : 0
            root.artUrl = root.safeArtUrl(object.artUrl)
            root.artDark = object.artDark !== false
            root.artAccent = root.safeText(object.artAccent, 32)
        } else {
            if (object.artUrl)
                root.artUrl = root.safeArtUrl(object.artUrl)
            if (isFinite(nextDuration) && nextDuration > 0)
                root.duration = nextDuration
            if (isFinite(nextPosition) && nextPosition >= 0
                    && Date.now() >= root._ignorePositionUntil) {
                root.position = root.duration > 0
                    ? Math.min(nextPosition, root.duration) : nextPosition
            }
            if (object.artAccent)
                root.artAccent = root.safeText(object.artAccent, 32)
        }

        root.status = nextStatus
        root.title = nextTitle
        root.artist = nextArtist
        root.mediaUrl = nextUrl

        if (!root.hasMedia) {
            root.artUrl = ""
            root.mediaUrl = ""
            root._trackKey = ""
        } else if (changed) {
            root.bootstrapTimeline()
        }
    }

    function playPause() {
        if (!root.enabled)
            return
        if (root.status === "Playing")
            root.status = "Paused"
        else if (root.status === "Paused")
            root.status = "Playing"
        controlProc.command = ["/usr/bin/playerctl", "--player=playerctld", "play-pause"]
        controlProc.running = true
    }

    function next() {
        if (!root.enabled)
            return
        root.position = 0
        controlProc.command = ["/usr/bin/playerctl", "--player=playerctld", "next"]
        controlProc.running = true
        timelineRefreshDelay.restart()
    }

    function previous() {
        if (!root.enabled)
            return
        root.position = 0
        controlProc.command = ["/usr/bin/playerctl", "--player=playerctld", "previous"]
        controlProc.running = true
        timelineRefreshDelay.restart()
    }

    function seekTo(seconds) {
        if (!root.enabled || root.duration <= 0)
            return
        const target = Math.max(0, Math.min(root.duration, Number(seconds)))
        root.position = target
        root._ignorePositionUntil = Date.now() + 900
        seekProc.command = ["/usr/bin/playerctl", "--player=playerctld",
                            "position", target.toFixed(3)]
        seekProc.running = true
    }

    onHasMediaChanged: {
        if (!root.hasMedia) {
            root.position = 0
            root.duration = 0
            timelineBootstrap.stop()
        }
    }

    onDetailedVisibleChanged: if (root.detailedVisible) root.refreshTimeline()
    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
            followProc.running = true;
        } else {
            mediaProc.running = false;
            followProc.running = false;
            positionProc.running = false;
            durationProc.running = false;
            controlProc.running = false;
            seekProc.running = false;
            followDebounce.stop();
            followRespawn.stop();
            timelineBootstrap.stop();
            timelineRefreshDelay.stop();
            root.status = "none";
            root.title = "";
            root.artist = "";
            root.artUrl = "";
            root.mediaUrl = "";
            root.position = 0;
            root.duration = 0;
        }
    }

    Component.onCompleted: if (root.enabled) {
        root.refresh();
        followProc.running = true;
    }

    Process {
        id: mediaProc
        command: ["/usr/bin/setpriv", "--pdeathsig", "TERM", "--",
                  "/usr/bin/python3", root.mediaInfoPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim()
                if (line === "")
                    return
                try {
                    root.applySnapshot(JSON.parse(line))
                } catch (error) {}
            }
        }
        onRunningChanged: if (!running) Qt.callLater(() => {
            if (root._mediaRefreshPending)
                root.refresh()
        })
    }

    Process { id: controlProc; command: ["/usr/bin/true"] }
    Process { id: seekProc; command: ["/usr/bin/true"] }

    Process {
        id: positionProc
        command: ["/usr/bin/playerctl", "--player=playerctld", "position"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = Number(text.trim())
                if (isFinite(value) && value >= 0
                        && Date.now() >= root._ignorePositionUntil) {
                    root.position = root.duration > 0
                        ? Math.min(value, root.duration) : value
                }
            }
        }
    }

    Process {
        id: durationProc
        command: ["/usr/bin/true"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const object = JSON.parse(text.trim())
                    if (root._durationRequestUrl !== root.mediaUrl)
                        return
                    const value = Number(object.duration || 0)
                    if (isFinite(value) && value > 0) {
                        root.duration = value
                        root.position = Math.min(root.position, value)
                    }
                    if (root.artUrl === "" && object.thumbnail)
                        root.artUrl = root.safeArtUrl(object.thumbnail)
                } catch (error) {}
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
        interval: root.detailedVisible ? 250 : 1000
        running: root.hasMedia
        repeat: true
        onTriggered: {
            if (root.isPlaying) {
                const nextPosition = root.position + interval / 1000
                root.position = root.duration > 0
                    ? Math.min(root.duration, nextPosition) : nextPosition
            }
            if (!root.detailedVisible)
                return
            root._positionTicks++
            if (root._positionTicks % 4 === 0)
                root.refreshPosition()
            if ((root.duration <= 0 && root._positionTicks % 4 === 0)
                    || root._positionTicks % 20 === 0) {
                root.refreshDuration()
            }
        }
    }

    Process {
        id: followProc
        command: ["/usr/bin/setpriv", "--pdeathsig", "TERM", "--",
                  "/usr/bin/playerctl", "--player=playerctld",
                  "metadata", "--format", "{{status}}|{{title}}", "--follow"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                followDebounce.restart()
                root.refreshTimeline()
            }
        }
        onRunningChanged: if (!running && root.enabled) followRespawn.restart()
    }

    Timer { id: followDebounce; interval: 150; onTriggered: root.refresh() }
    Timer { id: followRespawn; interval: 5000; onTriggered: if (root.enabled) followProc.running = true }
    Timer { interval: 60000; running: root.enabled; repeat: true; onTriggered: root.refresh() }
}
