pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
    // Names of monitors whose active workspace currently has a REAL fullscreen
    // window (not just maximized) — see poll-clients.sh. Lets the dock auto-hide
    // on that screen even while pinned/always-visible (Super+V).
    property var fullscreenMonitors: []

    // macOS "Turn Hiding Off": when true every dock stays permanently revealed.
    // Toggled by Super+V via the IpcHandler below; persisted across restarts.
    property bool pinnedVisible: false

    // True while the launchpad is open — the real dock rises above the launchpad
    // backdrop (it's mapped after the launchpad, so it stacks on top) so there's
    // ONE dock, not a separate in-launchpad replica. Set by the launchpad.
    property bool launchpadOpen: false
    // Screen name the launchpad is on, so only that monitor's dock rises.
    property string launchpadScreen: ""
    // Launchpad drag-to-pin coordination. While the launchpad drags an app over
    // the dock it publishes the cursor's screen X here; the dock on that screen
    // computes the insertion slot (launchpadDropIndex) and slides its icons apart
    // to open a gap there. The launchpad reads the slot back on drop.
    property bool launchpadDragActive: false
    property real launchpadDragX: 0
    property int  launchpadDropIndex: -1
    // Same idea for the Mission Control overview: while it's open the dock rises
    // and floats above its backdrop (reusing launchpadCloseRequested to dismiss).
    property bool overviewOpen: false
    property string overviewScreen: ""
    // Emitted when a dock click should dismiss the open launchpad (launching /
    // focusing an app behind it). The launchpad window listens and closes.
    signal launchpadCloseRequested()

    readonly property var excludedClasses: ["xembedsniproxy", "xwaylandvideobridge", ""]

    // Signature of the last poll payload. Reassigning identical data every tick
    // handed the dock's Repeaters a brand-new array/object each time, tearing
    // down and recreating every running-app icon twice a second.
    property string _sig: ""

    function _canonicalClass(cls) {
        let lc = (cls || "").toLowerCase()
        if (lc === "steam_proton" || lc === "explorer.exe") return "net.lutris.ableton-2"
        return lc
    }

    function _canonicalizeByClass(source) {
        let result = ({})
        let classes = Object.keys(source || {})
        for (let i = 0; i < classes.length; i++) {
            let key = root._canonicalClass(classes[i])
            result[key] = (result[key] || []).concat(source[classes[i]] || [])
        }
        return result
    }

    Process {
        id: pollProc
        command: [Quickshell.shellDir + "/dock/poll-clients.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = text.trim()
                if (raw === root._sig) return
                try {
                    let data = JSON.parse(raw)
                    root._sig = raw
                    let excl = root.excludedClasses
                    let byClass = root._canonicalizeByClass(data.byClass || {})
                    root.clientsByClass = byClass
                    root.activeWs = (typeof data.activeWs === "number") ? data.activeWs : -1
                    root.fullscreenMonitors = Array.isArray(data.fullscreenMonitors) ? data.fullscreenMonitors : []
                    root.focusedClass = root._canonicalClass(data.focused)
                    let classes = Object.keys(byClass).filter(c => c && !excl.includes(c))
                    if (JSON.stringify(classes) !== JSON.stringify(root.runningClasses))
                        root.runningClasses = classes
                } catch(e) {}
            }
        }
    }

    function refresh() { if (!pollProc.running) pollProc.running = true }

    // Event-driven: any Hyprland event (open/close/move/focus/title/workspace)
    // schedules one debounced poll, replacing the old blind 500ms timer that
    // spawned bash + 3×hyprctl + 3×jq continuously.
    Connections {
        target: Hyprland
        function onRawEvent(event) { pollDebounce.restart() }
    }
    Timer { id: pollDebounce; interval: 16; onTriggered: root.refresh() }

    // Slow backstop in case an event is ever missed.
    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        pollProc.running = true
        root.pinnedVisible = (visStore.text().trim() === "1")
        root._loadPins()
    }

    // ── Pinned apps — the single source of truth ──────────────────────────
    // Both the dock (DockWindow) and the launchpad read/mutate this one in-memory
    // list, so a pin made anywhere (dock right-click, launchpad drag-to-dock) shows
    // up everywhere instantly — no second copy, no file-watch race between surfaces.
    // dock-pinned.json is write-only persistence: loaded once at startup, then
    // rewritten on every change. We deliberately do NOT watch it — FileView.text()
    // lags one write behind, so reloading on our own setText() would revert each
    // change to its previous state (the "have to do it twice" bug).
    property var pinnedApps: []
    readonly property var pinnedClasses: pinnedApps.map(a => (a.wmClass || "").toLowerCase())

    // Class → friendly name + icon (also used to guess a launch command below).
    readonly property string kakaoIcon: "file://" + Quickshell.env("HOME")
        + "/.local/share/icons/hicolor/256x256/apps/DDB7_KakaoTalk.0.png"

    // Seed list, used only the first time (no store file yet). After that the
    // pinned set is user-managed and persisted to disk.
    readonly property var defaultPins: [
        { name: "Files",     wmClass: "org.gnome.Nautilus", iconName: "org.gnome.Nautilus", execCmd: ["gtk-launch", "org.gnome.Nautilus"] },
        { name: "Chrome",    wmClass: "google-chrome",      iconName: "google-chrome",      execCmd: ["gtk-launch", "google-chrome"] },
        { name: "KakaoTalk", wmClass: "kakaotalk.exe",      iconName: root.kakaoIcon,        execCmd: ["gtk-launch", "wine-Programs-KakaoTalk"] },
        { name: "Spotify",   wmClass: "spotify",            iconName: "spotify-client",     execCmd: ["gtk-launch", "spotify"] }
    ]

    FileView {
        id: pinStore
        path: Quickshell.stateDir + "/dock-pinned.json"
        blockLoading: true   // synchronous read so data is ready in _loadPins()
        printErrors: false   // a missing file on first run is expected
    }
    function _loadPins() {
        let raw = pinStore.text()
        if (raw) {
            try {
                let p = JSON.parse(raw)
                if (Array.isArray(p)) {
                    let normalized = p.map(app => root._normalizePin(app))
                    root.pinnedApps = normalized
                    if (JSON.stringify(normalized) !== JSON.stringify(p)) root._persist()
                    return
                }
            } catch (e) {}
        }
        root.pinnedApps = root.defaultPins   // first run: seed + persist the defaults
        pinStore.setText(JSON.stringify(root.pinnedApps))
    }
    function _persist() { pinStore.setText(JSON.stringify(root.pinnedApps)) }

    function _normalizePin(app) {
        let normalized = {
            name: app.name,
            wmClass: app.wmClass,
            iconName: app.iconName,
            execCmd: app.execCmd
        }
        let cls = (normalized.wmClass || "").toLowerCase()
        if (cls === "kakaotalk.exe") normalized.iconName = root.kakaoIcon
        if (cls === "serato dj pro.exe")
            normalized.execCmd = [Quickshell.env("HOME") + "/.local/bin/serato-dj-pro"]
        if (cls === "net.lutris.ableton-2" || cls === "steam_proton" || cls === "explorer.exe") {
            normalized.name = "Ableton"
            normalized.wmClass = "net.lutris.ableton-2"
            normalized.iconName = "lutris_ableton"
            normalized.execCmd = ["gtk-launch", "net.lutris.ableton-2"]
        }
        return normalized
    }

    function isPinned(cls) { return pinnedClasses.includes((cls || "").toLowerCase()) }

    function _mkEntry(app) {
        let cmd = (app.execCmd && app.execCmd.length > 0) ? app.execCmd : root._guessExec(app.wmClass)
        return { name: app.name, wmClass: app.wmClass, iconName: app.iconName, execCmd: cmd }
    }
    function pinApp(app) { root.pinAppAt(app, root.pinnedApps.length) }
    function pinAppAt(app, idx) {
        let cls = (app.wmClass || "").toLowerCase()
        if (!cls || root.isPinned(cls)) return
        let arr = root.pinnedApps.slice()
        arr.splice(Math.max(0, Math.min(arr.length, idx)), 0, root._mkEntry(app))
        root.pinnedApps = arr
        root._persist()
    }
    function unpinApp(cls) {
        cls = (cls || "").toLowerCase()
        root.pinnedApps = root.pinnedApps.filter(a => (a.wmClass || "").toLowerCase() !== cls)
        root._persist()
    }
    function reorderPins(from, to) {
        if (from < 0) return
        to = Math.max(0, Math.min(to, root.pinnedApps.length - 1))
        if (to === from) return
        let arr = root.pinnedApps.slice()
        arr.splice(to, 0, arr.splice(from, 1)[0])
        root.pinnedApps = arr
        root._persist()
    }

    // Class → friendly name + icon. Single source of truth for the dock's
    // class remapping — DockWindow's live-app row reuses this too.
    function _remapClass(cls) {
        let lc = cls.toLowerCase()
        if (lc === "net.lutris.ableton-2" || lc === "steam_proton" || lc === "explorer.exe")
            return { name: "Ableton", iconName: "lutris_ableton", base: "net.lutris.ableton-2", exact: true }
        if (lc === "kakaotalk.exe") return { name: "KakaoTalk", iconName: root.kakaoIcon, base: cls, exact: true }
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        let base = m ? m[1] : cls
        let baseLc = base.toLowerCase()
        if (baseLc === "code") return { name: "VS Code", iconName: "visual-studio-code", base: base, exact: false }
        if (baseLc === "com.transmissionbt.transmission")
            return { name: "Transmission", iconName: "transmission", base: base, exact: false }
        return { name: base, iconName: base, base: base, exact: false }
    }

    // Resolve a runnable launch command for an app we only know by window class,
    // reusing the dock's class→desktop-entry heuristic.
    function _guessExec(wmClass) {
        if ((wmClass || "").toLowerCase() === "serato dj pro.exe")
            return [Quickshell.env("HOME") + "/.local/bin/serato-dj-pro"]
        let m = root._remapClass(wmClass || "")
        let de = DesktopEntries.heuristicLookup(m.base)
        if (de && de.id) return ["gtk-launch", de.id]
        return []
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
