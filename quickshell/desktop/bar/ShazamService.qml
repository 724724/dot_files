pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Music Recognition (Shazam) state for the bar. Owns the search history, the
// recognize() pipeline and the popup's visibility, mirroring ClockService so
// the bar widget and popup window can both drive it from this directory.
//
// Recognition runs in a detached pipeline (capture → songrec → notify), so it
// keeps going and still fires its notification even after the popup is closed.
Singleton {
    id: root

    // Popup visibility, flipped directly by the bar ShazamWidget. The popup
    // window watches this; the IpcHandler mirrors it for external triggers.
    property bool popupVisible: false

    // Monitor whose Shazam button was tapped, so the popup opens there.
    property var targetScreen: null

    // Screen-space X of the Shazam button's centre, set by the widget on click
    // so the popup can drop down centred under the icon.
    property real anchorX: 0

    // True while a recognition is in flight (header pulses + spinner).
    property bool recognizing: false

    // Transient header subtitle ("Listening…", "No match found", errors).
    // Empty string falls back to the "N Songs" count.
    property string statusMsg: ""

    // Where recognition listens: "internal" fingerprints the default sink's
    // monitor (what the desktop is playing), "external" the default source
    // (microphone — music playing in the room). Persisted across restarts.
    property string audioSource: "internal"

    function setAudioSource(src) {
        if (src !== "internal" && src !== "external") return
        root.audioSource = src
        prefs.setText(JSON.stringify({ audioSource: src }))
    }

    FileView {
        id: prefs
        path: Quickshell.stateDir + "/shazam-prefs.json"
        blockLoading: true
        printErrors: false   // a missing file on first run is expected
    }

    // ── Filesystem paths ─────────────────────────────────────────────────
    // Real absolute paths (NOT Qt.resolvedUrl, which Quickshell maps to a
    // virtual qrc path that breaks shell commands) — matches SysUsageService.
    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
    }
    readonly property string scriptsDir: _configDir + "/quickshell/scripts"
    readonly property string iconUrl: "file://" + _configDir + "/quickshell/assets/shazam.svg"

    // ── History ──────────────────────────────────────────────────────────
    // Newest first. Each entry: { title, artist, coverart, spotify, shazamUrl, ts }.
    property var history: []
    readonly property int count: history.length

    FileView {
        id: store
        path: Quickshell.stateDir + "/shazam-history.json"
        blockLoading: true   // synchronous read so history is ready in onCompleted
        printErrors: false   // a missing file on first run is expected
    }
    Component.onCompleted: root._load()

    function _load() {
        let raw = store.text()
        if (raw) {
            try {
                let p = JSON.parse(raw)
                if (Array.isArray(p)) root.history = p
            } catch (e) { /* empty or corrupt — start fresh */ }
        }
        try {
            let s = JSON.parse(prefs.text() || "")
            if (s && (s.audioSource === "internal" || s.audioSource === "external"))
                root.audioSource = s.audioSource
        } catch (e) { /* first run — keep the "internal" default */ }
    }
    function _persist() { store.setText(JSON.stringify(root.history)) }

    // ── Recognition ──────────────────────────────────────────────────────
    function recognize() {
        if (root.recognizing) return
        root.recognizing = true
        root.statusMsg = "Listening…"
        recognizeProc.running = true
    }

    Process {
        id: recognizeProc
        command: ["bash", root.scriptsDir + "/shazam-recognize.sh", "8", root.audioSource]
        stdout: StdioCollector { onStreamFinished: root._onResult(text) }
        // Safety net: never leave the spinner stuck on if the script dies
        // without producing parseable output.
        onExited: root.recognizing = false
    }

    function _onResult(text) {
        root.recognizing = false
        let res
        try { res = JSON.parse((text || "").trim()) }
        catch (e) { root.statusMsg = "Recognition error"; root._clearStatusLater(); return }

        if (!res || res.status !== "ok") {
            root.statusMsg = (res && res.status === "nomatch")
                ? "No match found"
                : ("Error: " + ((res && res.message) || "unknown"))
            root._clearStatusLater()
            return
        }

        let entry = {
            title: res.title || "Unknown track",
            artist: res.artist || "",
            coverart: res.coverart || "",
            link: res.link || "",          // Apple Music (or Shazam page) URL
            shazamUrl: res.shazamUrl || "",
            ts: Date.now()
        }

        // De-duplicate: if this song is already in the list, drop the old copy
        // and re-add it on top so it becomes the most recent. Keyed on
        // title+artist, case-insensitive.
        let key = (entry.title + "|" + entry.artist).toLowerCase()
        let rest = root.history.filter(function (e) {
            return ((e.title || "") + "|" + (e.artist || "")).toLowerCase() !== key
        })
        root.history = [entry].concat(rest)   // new array so the ListView re-binds
        root._persist()
        root.statusMsg = ""

        // Only notify when the popup is closed — i.e. recognition ran in the
        // background. With the popup open the user already sees the new row.
        // The notification handles its own "Open in Apple Music" action detached.
        if (!root.popupVisible) {
            Quickshell.execDetached(["bash", root.scriptsDir + "/shazam-notify.sh",
                entry.title, entry.artist, res.coverLocal || "", entry.link])
        }
    }

    Timer { id: statusTimer; interval: 3500; onTriggered: root.statusMsg = "" }
    function _clearStatusLater() { statusTimer.restart() }

    // ── History operations ───────────────────────────────────────────────
    function openLink(i) {
        let e = root.history[i]
        if (!e) return
        // Open the song's Shazam page (lists the track with links to every
        // streaming service). Older rows may only carry other URL fields; fall
        // back to a Shazam search built from the title + artist.
        let url = e.shazamUrl || e.link
        if (!url || url.indexOf("shazam.com") === -1) {
            let q = encodeURIComponent(((e.title || "") + " " + (e.artist || "")).trim())
            url = "https://www.shazam.com/search/" + q
        }
        Quickshell.execDetached(["xdg-open", url])
    }
    function remove(i) {
        if (i < 0 || i >= root.history.length) return
        let next = root.history.slice()
        next.splice(i, 1)
        root.history = next
        root._persist()
    }
    function clearAll() { root.history = []; root._persist() }

    // ── Relative-time labels, refreshed on a 30s tick ────────────────────
    property int _tick: 0
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root._tick++ }

    function timeLabel(ts) {
        let _ = root._tick   // dependency so labels refresh
        if (!ts) return ""
        let diff = (Date.now() - ts) / 1000
        if (diff < 60)    return "just now"
        if (diff < 3600)  { let m = Math.floor(diff / 60);   return m + (m === 1 ? " minute ago" : " minutes ago") }
        if (diff < 86400) { let h = Math.floor(diff / 3600); return h + (h === 1 ? " hour ago"   : " hours ago") }
        return Qt.formatDate(new Date(ts), "yyyy-MM-dd")
    }

    IpcHandler {
        target: "shazam"
        function toggle()    { root.popupVisible = !root.popupVisible }
        function show()      { root.popupVisible = true }
        function hide()      { root.popupVisible = false }
        function recognize() { root.recognize() }
        function setSource(src: string): void { root.setAudioSource(src) }
    }
}
