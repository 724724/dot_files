pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Spotify playlist/track downloader. The backend (scripts/spotify-download.py)
// reads the track list from Spotify's public embed page (first 100 tracks) and
// downloads the matching audio with yt-dlp + ffmpeg — no spotdl, no login.
// Mirrors YoutubeService's event protocol; audio-only.
Singleton {
    id: root

    readonly property string helper: {
        let base = Quickshell.env("XDG_CONFIG_HOME")
        if (!base || base === "") base = Quickshell.env("HOME") + "/.config"
        return base + "/quickshell/scripts/spotify-download.py"
    }
    readonly property var audioFormats: [
        { id: "mp3", label: "MP3 · Best VBR" },
        { id: "m4a", label: "M4A · Apple compatible" },
        { id: "flac", label: "FLAC · Lossless output" },
        { id: "opus", label: "Opus · Efficient" },
        { id: "wav", label: "WAV · Uncompressed" }
    ]
    readonly property var bitrates: [
        { id: "auto", label: "Auto bitrate" },
        { id: "320k", label: "320 kbps" },
        { id: "256k", label: "256 kbps" },
        { id: "192k", label: "192 kbps" },
        { id: "128k", label: "128 kbps" }
    ]

    property bool available: false
    property string outputDir: ""
    property bool inspecting: false
    property string inspectedInput: ""
    property var metadata: ({})
    property string inspectError: ""
    property bool busy: false
    property real progress: 0
    property string phase: "Idle"
    property string speed: ""
    property string eta: ""
    property string title: ""
    property string outputPath: ""
    property bool playlist: false
    property int itemIndex: 0
    property int itemCount: 0
    property int completedItems: 0
    property var mediaInfo: ({})
    property string error: ""
    property bool _terminal: false

    function formatUploadDate(value) {
        value = String(value || "")
        return value.length === 8
            ? value.slice(0, 4) + "." + value.slice(4, 6) + "." + value.slice(6, 8)
            : value
    }

    function mediaSummary() {
        let value = root.mediaInfo || ({})
        if (Number(value.audioBitrateKbps) > 0) {
            let codec = value.audioCodec ? String(value.audioCodec).toUpperCase() + " · " : ""
            let sample = Number(value.sampleRateHz) > 0 ? " · " + Math.round(Number(value.sampleRateHz) / 1000) + " kHz" : ""
            return codec + Number(value.audioBitrateKbps) + " kbps" + sample
        }
        return ""
    }

    function refresh() {
        if (statusProcess.running) return
        statusProcess.running = true
    }

    function inspect(input) {
        input = (input || "").trim()
        if (!input || inspectProcess.running) return
        root.inspecting = true
        root.inspectedInput = input
        root.metadata = ({})
        root.inspectError = ""
        inspectProcess.command = ["python3", root.helper, "info", "--input", input]
        inspectProcess.running = true
    }

    function start(input, audioFormat, bitrate) {
        input = (input || "").trim()
        if (!root.available || root.busy || !input) return
        root.busy = true
        root.progress = 0
        root.phase = "Preparing download…"
        root.speed = ""
        root.eta = ""
        root.title = root.metadata.title || ""
        root.outputPath = ""
        root.playlist = false
        root.itemIndex = 0
        root.itemCount = 0
        root.completedItems = 0
        root.mediaInfo = ({})
        root.error = ""
        root._terminal = false
        downloadProcess.command = ["python3", root.helper, "download", "--input", input,
                                   "--audio-format", audioFormat || "mp3",
                                   "--bitrate", bitrate || "auto"]
        downloadProcess.running = true
    }

    function cancel() {
        if (!root.busy) return
        root._terminal = true
        downloadProcess.running = false
        root.busy = false
        root.phase = "Cancelled"
        root.speed = ""
        root.eta = ""
    }

    function openOutput() {
        if (root.outputDir) Quickshell.execDetached(["xdg-open", root.outputDir])
    }

    function setOutputDirectory(path) {
        path = (path || "").trim()
        if (!path || outputProcess.running) return
        outputProcess.command = ["python3", root.helper, "set-output", "--path", path]
        outputProcess.running = true
    }

    function formatDuration(seconds) {
        seconds = Math.max(0, Number(seconds) || 0)
        let hours = Math.floor(seconds / 3600)
        let minutes = Math.floor((seconds % 3600) / 60)
        let rest = Math.floor(seconds % 60)
        return hours > 0
            ? hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (rest < 10 ? "0" : "") + rest
            : minutes + ":" + (rest < 10 ? "0" : "") + rest
    }

    function _readStatus(text) {
        try {
            let value = JSON.parse((text || "").trim())
            root.available = value.ok === true
            root.outputDir = value.outputDir || ""
        } catch (e) {
            root.available = false
        }
    }

    function _readInfo(text) {
        try {
            let value = JSON.parse((text || "").trim())
            if (value.ok) root.metadata = value
            else root.inspectError = value.error || "Unable to read Spotify information."
        } catch (e) {
            root.inspectError = "Unable to read Spotify information."
        }
    }

    function _readOutput(text) {
        try {
            let value = JSON.parse((text || "").trim())
            if (value.ok) root.outputDir = value.outputDir || root.outputDir
            else root.error = value.error || "Unable to change the download folder."
        } catch (e) {
            root.error = "Unable to change the download folder."
        }
    }

    function _readDownload(line) {
        try {
            let value = JSON.parse((line || "").trim())
            if (value.event === "starting") {
                root.outputDir = value.outputDir || root.outputDir
                root.playlist = value.playlist === true
                root.phase = "Connecting…"
            } else if (value.event === "item") {
                root.title = value.title || root.title
                root.itemIndex = Number(value.index) || 0
                root.itemCount = Number(value.count) || root.itemCount
                root.phase = root.itemCount > 1
                    ? "Downloading " + root.itemIndex + " of " + root.itemCount + "…"
                    : "Downloading…"
            } else if (value.event === "progress") {
                root.progress = Number(value.progress) || 0
                root.itemIndex = Number(value.index) || root.itemIndex
                root.itemCount = Number(value.count) || root.itemCount
                root.speed = value.speed || ""
                root.eta = value.eta || ""
                root.phase = root.itemCount > 1
                    ? "Downloading " + root.itemIndex + " of " + root.itemCount + "…"
                    : "Downloading…"
            } else if (value.event === "itemCompleted") {
                root.outputPath = value.path || root.outputPath
                root.completedItems = Number(value.completed) || root.completedItems
            } else if (value.event === "processing") {
                root.phase = value.message || "Finishing media and metadata…"
                root.speed = ""
                root.eta = ""
            } else if (value.event === "completed") {
                root._terminal = true
                root.progress = 100
                root.outputPath = value.path || ""
                root.outputDir = value.outputDir || root.outputDir
                root.mediaInfo = value.mediaInfo || ({})
                root.completedItems = Number(value.files) || root.completedItems
                root.playlist = value.playlist === true
                let dl = Number(value.downloaded)
                let sk = Number(value.skipped)
                let fa = Number(value.failed)
                if (root.completedItems > 1) {
                    root.phase = "Saved " + root.completedItems
                    let extra = []
                    if (sk > 0) extra.push(sk + " already there")
                    if (fa > 0) extra.push(fa + " not found")
                    if (extra.length) root.phase += " (" + extra.join(", ") + ")"
                } else {
                    root.phase = sk > 0 ? "Already downloaded" : "Saved"
                }
                root.speed = ""
                root.eta = ""
            } else if (value.event === "error") {
                root._terminal = true
                root.error = value.message || "Download failed."
                root.phase = "Download failed"
            }
        } catch (e) {}
    }

    Component.onCompleted: root.refresh()

    Process {
        id: statusProcess
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { onStreamFinished: root._readStatus(text) }
    }

    Process {
        id: inspectProcess
        stdout: StdioCollector { onStreamFinished: root._readInfo(text) }
        onExited: root.inspecting = false
    }

    Process {
        id: outputProcess
        stdout: StdioCollector { onStreamFinished: root._readOutput(text) }
    }

    Process {
        id: downloadProcess
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._readDownload(data)
        }
        onExited: (code, status) => {
            if (!root._terminal && code !== 0) {
                root.error = "Download process stopped unexpectedly."
                root.phase = "Download failed"
            }
            root.busy = false
        }
    }
}
