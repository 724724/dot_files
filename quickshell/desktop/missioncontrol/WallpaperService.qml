pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Tracks the desktop wallpaper and keeps awww + Mission Control in sync.
//
// Sources of change, all converging on `current`:
//  - awww / wallpaper.sh runs (any image): picked up by `awww query`, which is
//    re-run every time Mission Control opens (MissionControlWindow calls
//    refresh()) — so the overview backdrop always matches the live wallpaper.
//  - Nautilus "Set as Background" (or anything else writing the GNOME
//    org.gnome.desktop.background picture-uri / picture-options keys): watched
//    via gsettings monitor; the new image and fit mode are applied to awww.
Singleton {
    id: root

    // Last known wallpaper path. Empty until the first awww/gsettings query
    // returns, so QML never tries to load a stale placeholder path.
    property string current: ""
    property string resizeMode: "crop"
    property string paddingColor: "#000000"
    readonly property int fillMode: root._fillMode(root.resizeMode)
    readonly property string configHome: {
        let configured = Quickshell.env("XDG_CONFIG_HOME")
        return configured && configured !== "" ? configured : Quickshell.env("HOME") + "/.config"
    }
    readonly property string wallpaperHelper: root.configHome + "/hypr/scripts/wallpaper.sh"

    function refresh() {
        if (!queryProc.running) queryProc.running = true
        if (!optionProc.running) optionProc.running = true
        if (!colorProc.running) colorProc.running = true
    }

    // `awww query` prints one line per output, e.g.
    //   ": eDP-1: 1920x1200, scale: 2, currently displaying: image: /path/img.png"
    // Take the first output's image (all outputs share one wallpaper here).
    Process {
        id: queryProc
        command: ["awww", "query"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let m = text.match(/image: (.+)/)
                let p = m ? m[1].trim() : ""
                if (p !== "" && p !== "/") root.current = p
            }
        }
    }

    Process {
        id: optionProc
        command: ["gsettings", "get", "org.gnome.desktop.background", "picture-options"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.resizeMode = root._modeFromGnome(text.trim().replace(/^'|'$/g, ""))
        }
    }

    Process {
        id: colorProc
        command: ["gsettings", "get", "org.gnome.desktop.background", "primary-color"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.paddingColor = root._normalizeColor(text.trim().replace(/^'|'$/g, ""))
        }
    }

    // Apply a wallpaper through wallpaper.sh so HEIF/HEIC inputs are converted
    // to a supported cached image before awww and Mission Control consume them.
    function apply(path, mode, color) {
        if (!path || path === "") return
        let m = root._normalizeMode(mode || root.resizeMode)
        let c = root._normalizeColor(color || root.paddingColor)
        root.resizeMode = m
        root.paddingColor = c
        root.current = path
        // Never run two helpers at once. A HEIF conversion takes seconds, so an
        // older run could finish AFTER a newer one and mirror its stale mode
        // back into gsettings — which is how "fit" silently became "fill".
        // Queueing keeps only the newest request, so the last word is correct.
        root._queuedApply = { path: path, mode: m, color: c }
        root._runQueuedApply()
    }
    property var _queuedApply: null
    function _runQueuedApply() {
        if (!root._queuedApply || applyProc.running) return
        let q = root._queuedApply
        root._queuedApply = null
        applyProc.command = [root.wallpaperHelper, q.path, q.mode, q.color]
        applyProc.running = true
    }
    Process {
        id: applyProc
        command: ["true"]
        onExited: root._runQueuedApply()
    }

    // Where wallpaper.sh drops converted HEIF/HEIC copies. A picture-uri
    // pointing in here is our own mirror write coming back, not a user change.
    readonly property string wallpaperCacheDir: {
        let c = Quickshell.env("XDG_CACHE_HOME")
        return (c && c !== "" ? c : Quickshell.env("HOME") + "/.cache") + "/hypr/wallpaper"
    }

    // Nautilus and the portal write picture-uri and picture-options as separate
    // keys. Reacting to each one on its own applies the image with the PREVIOUS
    // mode and then re-applies — the race above. Coalesce a burst into one apply.
    property string _pendingPath: ""
    property string _pendingMode: ""
    property string _pendingColor: ""
    Timer { id: settleTimer; interval: 400; onTriggered: root._flushPending() }

    function _flushPending() {
        let path = root._pendingPath !== "" ? root._pendingPath : root.current
        let mode = root._pendingMode !== "" ? root._pendingMode : root.resizeMode
        let color = root._pendingColor !== "" ? root._pendingColor : root.paddingColor
        root._pendingPath = ""
        root._pendingMode = ""
        root._pendingColor = ""
        if (path === "") return
        // Our own mirror write echoing back with the converted cache path:
        // adopt the path, but don't run the helper again.
        if (mode === root.resizeMode && color === root.paddingColor
                && path !== root.current && path.indexOf(root.wallpaperCacheDir) === 0) {
            root.current = path
            return
        }
        if (path === root.current && mode === root.resizeMode
                && color === root.paddingColor) return
        root.apply(path, mode, color)
    }

    // Nautilus "Set as Background" writes picture-uri (and picture-uri-dark in
    // dark mode). The local wallpaper portal also writes picture-options. React
    // to both and mirror the image/mode into awww.
    Process {
        command: ["setpriv", "--pdeathsig", "TERM", "--", "gsettings", "monitor",
                  "org.gnome.desktop.background"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                let opt = data.match(/picture-options: '(.+)'/)
                if (opt) {
                    root._pendingMode = root._modeFromGnome(opt[1])
                    settleTimer.restart()
                    return
                }
                let color = data.match(/primary-color: '(.+)'/)
                if (color) {
                    root._pendingColor = root._normalizeColor(color[1])
                    settleTimer.restart()
                    return
                }
                let m = data.match(/picture-uri(?:-dark)?: '(.+)'/)
                if (!m) return
                let p = root._fromUri(m[1])
                if (p !== "") {
                    root._pendingPath = p
                    settleTimer.restart()
                }
            }
        }
    }

    function _fromUri(u) {
        if (u.startsWith("file://")) u = u.substring(7)
        try { u = decodeURIComponent(u) } catch (e) {}
        return (u === "/") ? "" : u
    }

    function _normalizeMode(mode) {
        if (mode === "fit" || mode === "stretch" || mode === "no") return mode
        return "crop"
    }

    function _normalizeColor(color) {
        if (/^#[0-9a-fA-F]{6}$/.test(color)) return color
        return "#000000"
    }

    function _modeFromGnome(option) {
        if (option === "scaled") return "fit"
        if (option === "stretched") return "stretch"
        if (option === "centered" || option === "none" || option === "wallpaper") return "no"
        return "crop"
    }

    function _fillMode(mode) {
        if (mode === "fit") return Image.PreserveAspectFit
        if (mode === "stretch") return Image.Stretch
        if (mode === "no") return Image.Pad
        return Image.PreserveAspectCrop
    }
}
